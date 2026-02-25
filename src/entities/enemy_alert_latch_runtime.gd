## enemy_alert_latch_runtime.gd
## Phase 6 owner for alert-latch and zone domain.
class_name EnemyAlertLatchRuntime
extends RefCounted

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const AWARENESS_COMBAT := "COMBAT"
const ZONE_STATE_LOCKDOWN := 2
const COMBAT_ROOM_MIGRATION_HYSTERESIS_SEC := 0.2

var _owner: Node = null


func _init(owner: Node = null) -> void:
	_owner = owner


func bind(owner: Node) -> void:
	_owner = owner


func get_owner() -> Node:
	return _owner


func has_owner() -> bool:
	return _owner != null


func get_state_value(key: String, default_value: Variant = null) -> Variant:
	if _owner == null:
		return default_value
	var value: Variant = _owner.get(key)
	return default_value if value == null else value


func set_state_value(key: String, value: Variant) -> void:
	if _owner == null:
		return
	_owner.set(key, value)


func set_state_patch(values: Dictionary) -> void:
	if _owner == null:
		return
	for key_variant in values.keys():
		var key := String(key_variant)
		_owner.set(key, values[key_variant])


func is_combat_latched() -> bool:
	return bool(get_state_value("_combat_latched", false))


func get_combat_latched_room_id() -> int:
	return int(get_state_value("_combat_latched_room_id", -1))


func handle_alert_system_rebind(previous_alert_system: Node, next_alert_system: Node) -> void:
	if previous_alert_system == next_alert_system:
		return
	if not is_combat_latched():
		return
	var entity_id := int(get_state_value("entity_id", 0))
	if entity_id <= 0:
		return
	if previous_alert_system == null or not previous_alert_system.has_method("unregister_enemy_combat"):
		return
	previous_alert_system.unregister_enemy_combat(entity_id)
	set_state_value("_combat_latched", false)
	set_state_value("_combat_latched_room_id", -1)
	reset_combat_migration_candidate()
	set_state_value("_debug_last_latched", false)


func resolve_room_alert_snapshot() -> Dictionary:
	var room_id := _owner_resolve_room_id_for_events()
	var effective := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var transient := ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var latch_count := 0
	var alert_system := _current_alert_system()
	var nav_system := _current_nav_system()
	if room_id >= 0 and alert_system:
		if alert_system.has_method("get_room_effective_level"):
			effective = int(alert_system.get_room_effective_level(room_id))
		elif alert_system.has_method("get_room_alert_level"):
			effective = int(alert_system.get_room_alert_level(room_id))
		if alert_system.has_method("get_room_transient_level"):
			transient = int(alert_system.get_room_transient_level(room_id))
		else:
			transient = effective
		if alert_system.has_method("get_room_latch_count"):
			latch_count = int(alert_system.get_room_latch_count(room_id))
	elif room_id >= 0 and nav_system and nav_system.has_method("get_alert_level"):
		effective = int(nav_system.get_alert_level(room_id))
		transient = effective
	return {
		"effective": clampi(effective, ENEMY_ALERT_LEVELS_SCRIPT.CALM, ENEMY_ALERT_LEVELS_SCRIPT.COMBAT),
		"transient": clampi(transient, ENEMY_ALERT_LEVELS_SCRIPT.CALM, ENEMY_ALERT_LEVELS_SCRIPT.ALERT),
		"latch_count": maxi(latch_count, 0),
	}


func resolve_room_alert_level() -> int:
	var room_alert_snapshot := resolve_room_alert_snapshot()
	return int(room_alert_snapshot.get("effective", ENEMY_ALERT_LEVELS_SCRIPT.CALM))


func raise_room_alert_for_combat_same_tick() -> void:
	var alert_system := _current_alert_system()
	if alert_system == null or not alert_system.has_method("raise_combat_immediate"):
		return
	var room_id := _owner_resolve_room_id_for_events()
	if room_id < 0:
		return
	alert_system.raise_combat_immediate(room_id, int(get_state_value("entity_id", 0)))
	ensure_combat_latch_registered()


func sync_combat_latch_with_awareness_state(state_name: String) -> void:
	if bool(get_state_value("is_dead", false)):
		unregister_combat_latch()
		return
	var normalized := String(state_name).strip_edges().to_upper()
	if normalized == AWARENESS_COMBAT:
		ensure_combat_latch_registered()
		return
	_owner_reset_combat_runtime_state_bundles()
	if is_combat_latched():
		unregister_combat_latch()
	else:
		set_state_value("_combat_latched_room_id", -1)
		reset_combat_migration_candidate()


func ensure_combat_latch_registered() -> void:
	var entity_id := int(get_state_value("entity_id", 0))
	if entity_id <= 0:
		return
	var alert_system := _current_alert_system()
	if alert_system == null or not alert_system.has_method("register_enemy_combat"):
		return
	var latched_room_id := get_combat_latched_room_id()
	if is_combat_latched() and latched_room_id >= 0:
		var current_room_id := _owner_resolve_room_id_for_events()
		if current_room_id != latched_room_id:
			set_state_value("_debug_last_latched", true)
			return
		alert_system.register_enemy_combat(entity_id, latched_room_id)
		set_state_value("_debug_last_latched", true)
		return
	var room_id := _owner_resolve_room_id_for_events()
	if room_id < 0:
		return
	alert_system.register_enemy_combat(entity_id, room_id)
	set_state_value("_combat_latched", true)
	set_state_value("_combat_latched_room_id", room_id)
	set_state_value("_debug_last_latched", true)


func unregister_combat_latch() -> void:
	reset_combat_migration_candidate()
	_owner_reset_combat_runtime_state_bundles()
	var entity_id := int(get_state_value("entity_id", 0))
	var alert_system := _current_alert_system()
	if entity_id > 0 and alert_system and alert_system.has_method("unregister_enemy_combat") and is_combat_latched():
		alert_system.unregister_enemy_combat(entity_id)
	set_state_value("_combat_latched", false)
	set_state_value("_combat_latched_room_id", -1)
	set_state_value("_debug_last_latched", false)


func update_combat_latch_migration(delta: float) -> void:
	if not is_combat_latched():
		reset_combat_migration_candidate()
		return
	var entity_id := int(get_state_value("entity_id", 0))
	var alert_system := _current_alert_system()
	if entity_id <= 0 or alert_system == null or not alert_system.has_method("migrate_enemy_latch_room"):
		reset_combat_migration_candidate()
		return
	var current_room := _owner_resolve_room_id_for_events()
	if current_room < 0:
		reset_combat_migration_candidate()
		return
	if get_combat_latched_room_id() < 0:
		set_state_value("_combat_latched_room_id", current_room)
		reset_combat_migration_candidate()
		return
	if current_room == get_combat_latched_room_id():
		reset_combat_migration_candidate()
		return
	var candidate_room_id := int(get_state_value("_combat_migration_candidate_room_id", -1))
	if candidate_room_id != current_room:
		set_state_value("_combat_migration_candidate_room_id", current_room)
		set_state_value("_combat_migration_candidate_elapsed", maxf(delta, 0.0))
	else:
		set_state_value(
			"_combat_migration_candidate_elapsed",
			float(get_state_value("_combat_migration_candidate_elapsed", 0.0)) + maxf(delta, 0.0)
		)
	if float(get_state_value("_combat_migration_candidate_elapsed", 0.0)) < combat_room_migration_hysteresis_sec():
		return
	alert_system.migrate_enemy_latch_room(entity_id, current_room)
	set_state_value("_combat_latched_room_id", current_room)
	reset_combat_migration_candidate()


func reset_combat_migration_candidate() -> void:
	set_state_value("_combat_migration_candidate_room_id", -1)
	set_state_value("_combat_migration_candidate_elapsed", 0.0)


func combat_room_migration_hysteresis_sec() -> float:
	return maxf(
		float(get_state_value("COMBAT_ROOM_MIGRATION_HYSTERESIS_SEC", COMBAT_ROOM_MIGRATION_HYSTERESIS_SEC)),
		0.0
	)


func resolve_zone_state_for_room(room_id: int) -> int:
	var zone_director := _current_zone_director()
	if zone_director == null:
		return -1
	if not zone_director.has_method("get_zone_for_room") or not zone_director.has_method("get_zone_state"):
		return -1
	var zone_id := int(zone_director.get_zone_for_room(room_id))
	return int(zone_director.get_zone_state(zone_id))


func get_zone_state() -> int:
	var room_id := _owner_meta_room_id()
	return resolve_zone_state_for_room(room_id)


func is_zone_lockdown() -> bool:
	return resolve_zone_state_for_room(_owner_meta_room_id()) == _zone_state_lockdown_value()


func _owner_resolve_room_id_for_events() -> int:
	if _owner == null:
		return -1
	if _owner.has_method("_resolve_room_id_for_events"):
		return int(_owner.call("_resolve_room_id_for_events"))
	return _owner_meta_room_id()


func _owner_reset_combat_runtime_state_bundles() -> void:
	if _owner == null:
		return
	if _owner.has_method("_reset_combat_runtime_state_bundles"):
		_owner.call("_reset_combat_runtime_state_bundles")


func _owner_meta_room_id() -> int:
	if _owner == null:
		return -1
	return int(_owner.get_meta("room_id", -1))


func _zone_state_lockdown_value() -> int:
	return int(get_state_value("ZONE_STATE_LOCKDOWN", ZONE_STATE_LOCKDOWN))


func _current_alert_system() -> Node:
	return get_state_value("alert_system", null) as Node


func _current_nav_system() -> Node:
	return get_state_value("nav_system", null) as Node


func _current_zone_director() -> Node:
	return get_state_value("_zone_director", null) as Node
