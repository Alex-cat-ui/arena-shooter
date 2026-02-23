## enemy_aggro_coordinator.gd
## Centralized group aggro coordination (room ALERT + one-hop ALERT reinforcement).
class_name EnemyAggroCoordinator
extends Node

const ALERT_STATE := "ALERT"
const REASON_ROOM_ALERT_PROPAGATION := "room_alert_propagation"
const REASON_REINFORCEMENT := "reinforcement"
const REASON_TEAMMATE_CALL := "teammate_call"
const TEAMMATE_CALL_SOURCE_COOLDOWN_SEC := 8.0
const TEAMMATE_CALL_TARGET_COOLDOWN_SEC := 6.0

var navigation_service: Node = null
var entities_container: Node = null
var player_node: Node2D = null
var zone_director: Node = null
var _next_teammate_call_id: int = 1
var _next_reinforcement_call_id: int = 1
var _source_last_call_sec: Dictionary = {} # source_enemy_id -> last emitted sec
var _target_last_accept_sec: Dictionary = {} # target_enemy_id -> last accepted sec
var _target_call_dedup: Dictionary = {} # "target_id|call_id" -> true
var _debug_time_override_sec: float = -1.0


func initialize(p_entities_container: Node = null, p_navigation_service: Node = null, p_player_node: Node = null) -> void:
	bind_context(p_entities_container, p_navigation_service, p_player_node)
	_connect_event_bus_signals()


func bind_context(p_entities_container: Node = null, p_navigation_service: Node = null, p_player_node: Node = null) -> void:
	entities_container = p_entities_container
	navigation_service = p_navigation_service
	player_node = p_player_node as Node2D


func set_zone_director(director: Node) -> void:
	zone_director = director


func _connect_event_bus_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("enemy_state_changed") and not EventBus.enemy_state_changed.is_connected(_on_enemy_state_changed):
		EventBus.enemy_state_changed.connect(_on_enemy_state_changed)
	if EventBus.has_signal("enemy_teammate_call") and not EventBus.enemy_teammate_call.is_connected(_on_enemy_teammate_call):
		EventBus.enemy_teammate_call.connect(_on_enemy_teammate_call)


func _on_enemy_state_changed(enemy_id: int, from_state: String, to_state: String, room_id: int, reason: String) -> void:
	if not navigation_service:
		return
	if room_id < 0:
		return
	if to_state != ALERT_STATE:
		return
	if from_state != "SUSPICIOUS":
		return
	if not _is_valid_teammate_call_source(reason):
		return
	_emit_teammate_call(enemy_id, room_id)
	_call_reinforcements(enemy_id, room_id, reason, to_state)


func _on_enemy_teammate_call(source_enemy_id: int, source_room_id: int, call_id: int, _timestamp_sec: float, shot_pos: Vector2) -> void:
	if source_enemy_id <= 0 or source_room_id < 0 or call_id <= 0:
		return
	for enemy_variant in _get_all_enemies():
		var enemy := enemy_variant as Node
		if enemy == null:
			continue
		var target_enemy_id := int(enemy.get("entity_id")) if "entity_id" in enemy else -1
		if target_enemy_id <= 0 or target_enemy_id == source_enemy_id:
			continue
		var dedup_key := _teammate_call_dedup_key(target_enemy_id, call_id)
		if _target_call_dedup.has(dedup_key):
			continue
		var target_room_id := _resolve_enemy_room_id(enemy)
		if not _teammate_call_room_gate(source_room_id, target_room_id):
			continue
		_target_call_dedup[dedup_key] = true
		if not _can_target_accept_teammate_call(target_enemy_id):
			continue
		if not enemy.has_method("apply_teammate_call"):
			continue
		var accepted_variant: Variant = enemy.call("apply_teammate_call", source_enemy_id, source_room_id, call_id, shot_pos)
		var accepted := bool(accepted_variant)
		if accepted:
			_target_last_accept_sec[target_enemy_id] = _now_sec()
			var director := _resolve_zone_director()
			if director and director.has_method("record_accepted_teammate_call"):
				director.record_accepted_teammate_call(source_room_id, target_room_id)


func _is_valid_escalation_source(reason: String) -> bool:
	if reason == "":
		return false
	if reason == REASON_ROOM_ALERT_PROPAGATION:
		return false
	if reason == REASON_REINFORCEMENT:
		return false
	if reason == REASON_TEAMMATE_CALL:
		return false
	return true


func _is_valid_teammate_call_source(reason: String) -> bool:
	return _is_valid_escalation_source(reason)


func _emit_teammate_call(source_enemy_id: int, source_room_id: int) -> void:
	if not EventBus or not EventBus.has_method("emit_enemy_teammate_call"):
		return
	if source_enemy_id <= 0 or source_room_id < 0:
		return
	if not _can_source_emit_teammate_call(source_enemy_id):
		return
	var call_id := _next_teammate_call_id
	_next_teammate_call_id += 1
	var now_sec := _now_sec()
	_source_last_call_sec[source_enemy_id] = now_sec
	var shot_pos := Vector2.ZERO
	var source_node := _find_enemy_by_id(source_enemy_id)
	if source_node and "_investigate_anchor" in source_node and "_investigate_anchor_valid" in source_node:
		if bool(source_node.get("_investigate_anchor_valid")):
			shot_pos = source_node.get("_investigate_anchor") as Vector2
	EventBus.emit_enemy_teammate_call(source_enemy_id, source_room_id, call_id, now_sec, shot_pos)


func _can_source_emit_teammate_call(source_enemy_id: int) -> bool:
	var now_sec := _now_sec()
	var last_sec := float(_source_last_call_sec.get(source_enemy_id, -999999.0))
	return now_sec - last_sec >= TEAMMATE_CALL_SOURCE_COOLDOWN_SEC


func _can_target_accept_teammate_call(target_enemy_id: int) -> bool:
	var now_sec := _now_sec()
	var last_sec := float(_target_last_accept_sec.get(target_enemy_id, -999999.0))
	return now_sec - last_sec >= TEAMMATE_CALL_TARGET_COOLDOWN_SEC


func _teammate_call_room_gate(source_room_id: int, target_room_id: int) -> bool:
	return _is_same_or_adjacent_room(source_room_id, target_room_id)


func _is_same_or_adjacent_room(room_a: int, room_b: int) -> bool:
	if room_a < 0 or room_b < 0:
		return false
	if navigation_service and navigation_service.has_method("is_same_or_adjacent_room"):
		return bool(navigation_service.call("is_same_or_adjacent_room", room_a, room_b))
	if room_a == room_b:
		return true
	if navigation_service and navigation_service.has_method("is_adjacent"):
		return bool(navigation_service.call("is_adjacent", room_a, room_b))
	if navigation_service and navigation_service.has_method("get_neighbors"):
		var neighbors := navigation_service.get_neighbors(room_a) as Array
		return neighbors.has(room_b)
	return false


func _teammate_call_dedup_key(target_enemy_id: int, call_id: int) -> String:
	return "%d|%d" % [target_enemy_id, call_id]


func _get_all_enemies() -> Array:
	var result: Array = []
	if not entities_container:
		return result
	for child_variant in entities_container.get_children():
		var enemy := child_variant as Node
		if enemy and enemy.is_in_group("enemies"):
			result.append(enemy)
	return result


func _find_enemy_by_id(enemy_id: int) -> Node:
	if enemy_id <= 0:
		return null
	if not entities_container:
		return null
	for child_variant in entities_container.get_children():
		var enemy := child_variant as Node
		if enemy == null:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if not ("entity_id" in enemy):
			continue
		if int(enemy.get("entity_id")) == enemy_id:
			return enemy
	return null


func _now_sec() -> float:
	if _debug_time_override_sec >= 0.0:
		return _debug_time_override_sec
	return Time.get_ticks_msec() / 1000.0


func debug_set_time_override_sec(time_sec: float) -> void:
	_debug_time_override_sec = maxf(time_sec, 0.0)


func debug_clear_time_override_sec() -> void:
	_debug_time_override_sec = -1.0


func _call_reinforcements(source_enemy_id: int, source_room_id: int, reason: String, source_awareness_state: String = ALERT_STATE) -> void:
	if not _is_valid_reinforcement_source(reason):
		return
	if not EventBus or not EventBus.has_method("emit_enemy_reinforcement_called"):
		return
	var director := _resolve_zone_director()
	if director:
		if not director.has_method("validate_reinforcement_call"):
			return
		var call_id := _next_reinforcement_call_id
		_next_reinforcement_call_id += 1
		var validation: Dictionary = director.validate_reinforcement_call(
			source_enemy_id,
			source_room_id,
			source_awareness_state,
			call_id,
			_now_sec()
		) as Dictionary
		if not bool(validation.get("accepted", false)):
			return

	var target_room_ids := _select_reinforcement_rooms(source_room_id)
	if target_room_ids.is_empty():
		return
	var capped_target_room_ids := _apply_zone_caps(target_room_ids)
	if capped_target_room_ids.is_empty():
		return
	EventBus.emit_enemy_reinforcement_called(source_enemy_id, source_room_id, capped_target_room_ids)


func _is_valid_reinforcement_source(reason: String) -> bool:
	return _is_valid_escalation_source(reason)


func _select_reinforcement_rooms(source_room_id: int) -> Array[int]:
	if not navigation_service:
		return []
	var player_pos := _get_player_position()
	if navigation_service.has_method("pick_top2_neighbor_rooms_for_reinforcement"):
		var picked := navigation_service.pick_top2_neighbor_rooms_for_reinforcement(source_room_id, player_pos) as Array
		var normalized: Array[int] = []
		for rid_variant in picked:
			var rid := int(rid_variant)
			if rid >= 0:
				normalized.append(rid)
		return normalized
	if navigation_service.has_method("get_neighbors"):
		var neighbors := navigation_service.get_neighbors(source_room_id) as Array
		var normalized_neighbors: Array[int] = []
		for rid_variant in neighbors:
			var rid := int(rid_variant)
			if rid >= 0:
				normalized_neighbors.append(rid)
		return normalized_neighbors
	return []


func _apply_zone_caps(target_room_ids: Array[int]) -> Array[int]:
	var director := _resolve_zone_director()
	if not director:
		return target_room_ids
	if not director.has_method("get_zone_for_room"):
		return target_room_ids
	if not director.has_method("can_spawn_reinforcement"):
		return target_room_ids
	if not director.has_method("register_reinforcement_wave"):
		return target_room_ids

	var allowed_room_ids: Array[int] = []
	var reinforcement_by_zone: Dictionary = {}
	for rid_variant in target_room_ids:
		var room_id := int(rid_variant)
		var target_zone_id := int(director.get_zone_for_room(room_id))
		if target_zone_id < 0:
			allowed_room_ids.append(room_id)
			continue
		if not bool(director.can_spawn_reinforcement(target_zone_id)):
			continue
		allowed_room_ids.append(room_id)
		reinforcement_by_zone[target_zone_id] = int(reinforcement_by_zone.get(target_zone_id, 0)) + 1

	for zone_variant in reinforcement_by_zone.keys():
		var zone_id := int(zone_variant)
		var reinforcement_count := int(reinforcement_by_zone.get(zone_id, 0))
		director.register_reinforcement_wave(zone_id, reinforcement_count)

	return allowed_room_ids


func _resolve_zone_director() -> Node:
	if zone_director and is_instance_valid(zone_director):
		return zone_director
	if not get_tree():
		return null
	var root := get_tree().root
	if not root:
		return null
	var resolved := root.get_node_or_null("ZoneDirector")
	if resolved:
		zone_director = resolved
	return zone_director


func _resolve_enemy_room_id(enemy: Node) -> int:
	if not enemy:
		return -1
	if navigation_service and navigation_service.has_method("get_enemy_room_id"):
		return int(navigation_service.get_enemy_room_id(enemy))
	return int(enemy.get_meta("room_id", -1))


func _get_player_position() -> Vector2:
	if navigation_service and navigation_service.has_method("get_player_position"):
		return navigation_service.get_player_position() as Vector2
	if player_node and is_instance_valid(player_node):
		return player_node.global_position
	if RuntimeState:
		return Vector2(RuntimeState.player_pos.x, RuntimeState.player_pos.y)
	return Vector2.ZERO
