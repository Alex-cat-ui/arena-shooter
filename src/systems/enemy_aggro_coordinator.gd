## enemy_aggro_coordinator.gd
## Centralized group aggro coordination (room ALERT + one-hop COMBAT reinforcement).
class_name EnemyAggroCoordinator
extends Node

const ALERT_STATE := "ALERT"
const COMBAT_STATE := "COMBAT"
const REASON_ROOM_ALERT_PROPAGATION := "room_alert_propagation"
const REASON_VISION := "vision"
const REASON_NOISE_ESCALATED := "noise_escalated"
const REASON_CONFIRMED_CONTACT := "confirmed_contact"

var navigation_service: Node = null
var entities_container: Node = null
var player_node: Node2D = null
var zone_director: Node = null


func initialize(p_entities_container: Node = null, p_navigation_service: Node = null, p_player_node: Node = null) -> void:
	# Backward compatibility: initialize(navigation_service)
	if p_navigation_service == null and p_player_node == null and p_entities_container != null and p_entities_container.has_method("get_enemies_in_room"):
		bind_context(null, p_entities_container, null)
	else:
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


func _on_enemy_state_changed(enemy_id: int, _from_state: String, to_state: String, room_id: int, reason: String) -> void:
	if not navigation_service:
		return
	if room_id < 0:
		return
	if to_state == ALERT_STATE:
		_propagate_room_alert(enemy_id, room_id, reason)
	elif to_state == COMBAT_STATE:
		_call_reinforcements(enemy_id, room_id, reason)


func _propagate_room_alert(source_enemy_id: int, source_room_id: int, reason: String) -> void:
	if reason == REASON_ROOM_ALERT_PROPAGATION:
		return

	var enemies := _get_enemies_in_room(source_room_id)
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node
		if not enemy:
			continue
		if "entity_id" in enemy and int(enemy.entity_id) == source_enemy_id:
			continue
		var awareness_state := String(enemy.get_meta("awareness_state", "CALM"))
		if awareness_state == COMBAT_STATE:
			continue
		if enemy.has_method("apply_room_alert_propagation"):
			enemy.apply_room_alert_propagation(source_enemy_id, source_room_id)


func _call_reinforcements(source_enemy_id: int, source_room_id: int, reason: String) -> void:
	if not _is_valid_reinforcement_source(reason):
		return
	if not EventBus or not EventBus.has_method("emit_enemy_reinforcement_called"):
		return

	var target_room_ids := _select_reinforcement_rooms(source_room_id)
	if target_room_ids.is_empty():
		return
	var capped_target_room_ids := _apply_zone_caps(target_room_ids)
	if capped_target_room_ids.is_empty():
		return
	EventBus.emit_enemy_reinforcement_called(source_enemy_id, source_room_id, capped_target_room_ids)


func _is_valid_reinforcement_source(reason: String) -> bool:
	return reason == REASON_VISION or reason == REASON_NOISE_ESCALATED or reason == REASON_CONFIRMED_CONTACT


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


func _get_enemies_in_room(room_id: int) -> Array:
	if navigation_service and navigation_service.has_method("get_enemies_in_room"):
		return navigation_service.get_enemies_in_room(room_id) as Array
	if not entities_container:
		return []
	var result: Array = []
	for node_variant in entities_container.get_children():
		var enemy := node_variant as Node
		if not enemy:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if _resolve_enemy_room_id(enemy) != room_id:
			continue
		result.append(enemy)
	return result


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
