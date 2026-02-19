## enemy_alert_system.gd
## Room-level alert propagation/decay state machine driven by gameplay events.
class_name EnemyAlertSystem
extends Node

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var navigation_service: Node = null
var _room_transient_states: Dictionary = {} # room_id -> {"level": int, "ttl": float}
var _room_combat_latch: Dictionary = {}     # room_id -> {enemy_id: true}
var _enemy_latched_room: Dictionary = {}    # enemy_id -> room_id


func initialize(p_navigation_service: Node) -> void:
	bind_room_nav(p_navigation_service)
	_connect_event_bus_signals()
	reset_all()


func bind_room_nav(p_navigation_service: Node) -> void:
	navigation_service = p_navigation_service


func reset_all() -> void:
	_room_transient_states.clear()
	_room_combat_latch.clear()
	_enemy_latched_room.clear()


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	var room_ids: Array = _room_transient_states.keys()
	for rid_variant in room_ids:
		var room_id := int(rid_variant)
		if not _room_transient_states.has(room_id):
			continue
		var state := _room_transient_states[room_id] as Dictionary
		var level := clampi(
			int(state.get("level", ENEMY_ALERT_LEVELS_SCRIPT.CALM)),
			ENEMY_ALERT_LEVELS_SCRIPT.CALM,
			ENEMY_ALERT_LEVELS_SCRIPT.ALERT
		)
		if level <= ENEMY_ALERT_LEVELS_SCRIPT.CALM:
			_room_transient_states.erase(room_id)
			continue
		var ttl := maxf(0.0, float(state.get("ttl", 0.0)) - delta)
		if ttl > 0.0:
			state["ttl"] = ttl
			_room_transient_states[room_id] = state
			continue
		_decay_room_transient_level(room_id, level)


# Sole tick driver — level_mvp calls combat_system.update() but NOT alert_system.update().
# No external manual call exists; this _process is the single authority.
func _process(delta: float) -> void:
	update(delta)


func get_room_alert_level(room_id: int) -> int:
	return get_room_effective_level(room_id)


func get_room_transient_level(room_id: int) -> int:
	if room_id < 0:
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if not _room_transient_states.has(room_id):
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var state := _room_transient_states[room_id] as Dictionary
	return clampi(
		int(state.get("level", ENEMY_ALERT_LEVELS_SCRIPT.CALM)),
		ENEMY_ALERT_LEVELS_SCRIPT.CALM,
		ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	)


func get_room_latch_count(room_id: int) -> int:
	if room_id < 0:
		return 0
	if not _room_combat_latch.has(room_id):
		return 0
	var latch := _room_combat_latch[room_id] as Dictionary
	return latch.size()


func get_room_effective_level(room_id: int) -> int:
	if room_id < 0:
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if get_room_latch_count(room_id) > 0:
		return ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	return get_room_transient_level(room_id)


func get_room_alert_ttl(room_id: int) -> float:
	if room_id < 0 or not _room_transient_states.has(room_id):
		return 0.0
	var state := _room_transient_states[room_id] as Dictionary
	return maxf(0.0, float(state.get("ttl", 0.0)))


func get_alert_level_for_enemy(enemy: Node) -> int:
	if not enemy:
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id < 0 and navigation_service and navigation_service.has_method("get_enemy_room_id"):
		room_id = int(navigation_service.get_enemy_room_id(enemy))
	return get_room_alert_level(room_id)


func get_state_snapshot() -> Dictionary:
	return {
		"transient": _room_transient_states.duplicate(true),
		"combat_latch": _room_combat_latch.duplicate(true),
		"enemy_latched_room": _enemy_latched_room.duplicate(true),
	}


func register_enemy_combat(enemy_id: int, room_id: int) -> void:
	if enemy_id <= 0 or room_id < 0:
		return
	var current_room := int(_enemy_latched_room.get(enemy_id, -1))
	if current_room == room_id:
		var existing_latch := _room_combat_latch.get(room_id, {}) as Dictionary
		existing_latch[enemy_id] = true
		_room_combat_latch[room_id] = existing_latch
	else:
		if current_room >= 0:
			_remove_enemy_from_room_latch(enemy_id, current_room)
		_enemy_latched_room[enemy_id] = room_id
		var latch := _room_combat_latch.get(room_id, {}) as Dictionary
		latch[enemy_id] = true
		_room_combat_latch[room_id] = latch
	_raise_room_transient_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)


func unregister_enemy_combat(enemy_id: int) -> void:
	if enemy_id <= 0:
		return
	if not _enemy_latched_room.has(enemy_id):
		return
	var room_id := int(_enemy_latched_room.get(enemy_id, -1))
	_enemy_latched_room.erase(enemy_id)
	_remove_enemy_from_room_latch(enemy_id, room_id)


func migrate_enemy_latch_room(enemy_id: int, new_room_id: int) -> void:
	if enemy_id <= 0:
		return
	if new_room_id < 0:
		unregister_enemy_combat(enemy_id)
		return
	if not _enemy_latched_room.has(enemy_id):
		register_enemy_combat(enemy_id, new_room_id)
		return
	var old_room_id := int(_enemy_latched_room.get(enemy_id, -1))
	if old_room_id == new_room_id:
		return
	_enemy_latched_room[enemy_id] = new_room_id
	_remove_enemy_from_room_latch(enemy_id, old_room_id)
	var new_latch := _room_combat_latch.get(new_room_id, {}) as Dictionary
	new_latch[enemy_id] = true
	_room_combat_latch[new_room_id] = new_latch
	_raise_room_transient_level(new_room_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)


func raise_combat_immediate(room_id: int, source_enemy_id: int = -1) -> void:
	if room_id < 0:
		return
	if source_enemy_id > 0:
		register_enemy_combat(source_enemy_id, room_id)
	else:
		_raise_room_transient_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	for neighbor_id in _neighbor_rooms(room_id):
		_raise_room_transient_level(neighbor_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)


func _connect_event_bus_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("player_shot") and not EventBus.player_shot.is_connected(_on_player_shot):
		EventBus.player_shot.connect(_on_player_shot)
	if EventBus.has_signal("enemy_player_spotted") and not EventBus.enemy_player_spotted.is_connected(_on_enemy_player_spotted):
		EventBus.enemy_player_spotted.connect(_on_enemy_player_spotted)
	if EventBus.has_signal("enemy_killed") and not EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.connect(_on_enemy_killed)


func _on_player_shot(_weapon_type: String, position: Vector3, _direction: Vector3) -> void:
	var room_id := _room_id_at_position(Vector2(position.x, position.y))
	if room_id < 0:
		return
	_raise_room_transient_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	for neighbor_id in _neighbor_rooms(room_id):
		_raise_room_transient_level(neighbor_id, ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)


func _on_enemy_player_spotted(enemy_id: int, position: Vector3) -> void:
	var room_id := _room_id_at_position(Vector2(position.x, position.y))
	if room_id < 0:
		room_id = _resolve_enemy_room(enemy_id)
	if room_id < 0:
		return
	_raise_room_transient_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)


func _on_enemy_killed(enemy_id: int, _enemy_type: String) -> void:
	var room_id := _resolve_enemy_room(enemy_id)
	unregister_enemy_combat(enemy_id)
	if room_id < 0:
		return
	if not _room_has_alive_enemies(room_id):
		_room_transient_states.erase(room_id)
		return
	_raise_room_transient_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)


func _raise_room_transient_level(room_id: int, level: int) -> void:
	if room_id < 0:
		return
	var target_level := clampi(level, ENEMY_ALERT_LEVELS_SCRIPT.CALM, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	if target_level <= ENEMY_ALERT_LEVELS_SCRIPT.CALM:
		_room_transient_states.erase(room_id)
		return

	var current_level := get_room_transient_level(room_id)
	if target_level < current_level:
		return

	var new_ttl := ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(target_level)
	if _room_transient_states.has(room_id):
		var current := _room_transient_states[room_id] as Dictionary
		if target_level == current_level:
			new_ttl = maxf(new_ttl, float(current.get("ttl", 0.0)))
	_room_transient_states[room_id] = {
		"level": target_level,
		"ttl": new_ttl,
	}


func _decay_room_transient_level(room_id: int, level: int) -> void:
	var new_level := level - 1
	if new_level <= ENEMY_ALERT_LEVELS_SCRIPT.CALM:
		_room_transient_states.erase(room_id)
		return
	_room_transient_states[room_id] = {
		"level": new_level,
		"ttl": ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(new_level),
	}


func _room_id_at_position(pos: Vector2) -> int:
	if navigation_service and navigation_service.has_method("room_id_at_point"):
		return int(navigation_service.room_id_at_point(pos))
	return -1


func _neighbor_rooms(room_id: int) -> Array[int]:
	var out: Array[int] = []
	if room_id < 0 or not navigation_service:
		return out
	var neighbors: Array = []
	if navigation_service.has_method("get_neighbors"):
		neighbors = navigation_service.get_neighbors(room_id) as Array
	elif navigation_service.has_method("get_adjacent_room_ids"):
		neighbors = navigation_service.get_adjacent_room_ids(room_id) as Array
	for rid_variant in neighbors:
		var rid := int(rid_variant)
		if rid >= 0 and rid != room_id:
			out.append(rid)
	return out


func _resolve_enemy_room(enemy_id: int) -> int:
	if _enemy_latched_room.has(enemy_id):
		return int(_enemy_latched_room[enemy_id])
	if navigation_service and navigation_service.has_method("get_enemy_room_id_by_id"):
		var room_id := int(navigation_service.get_enemy_room_id_by_id(enemy_id))
		if room_id >= 0:
			return room_id
	return -1


func _remove_enemy_from_room_latch(enemy_id: int, room_id: int) -> void:
	if room_id < 0:
		return
	if not _room_combat_latch.has(room_id):
		return
	var latch := _room_combat_latch[room_id] as Dictionary
	latch.erase(enemy_id)
	if latch.is_empty():
		_room_combat_latch.erase(room_id)
		_maybe_clear_room_when_latch_empty(room_id)
		return
	_room_combat_latch[room_id] = latch


func _maybe_clear_room_when_latch_empty(room_id: int) -> void:
	if room_id < 0:
		return
	if get_room_latch_count(room_id) > 0:
		return
	if _room_has_alive_enemies(room_id):
		return
	_room_transient_states.erase(room_id)


func _room_has_alive_enemies(room_id: int) -> bool:
	if room_id < 0:
		return false
	if navigation_service and navigation_service.has_method("get_enemies_in_room"):
		var room_enemies := navigation_service.get_enemies_in_room(room_id) as Array
		return room_enemies.size() > 0
	var tree := get_tree()
	if tree == null:
		return false
	for enemy_variant in tree.get_nodes_in_group("enemies"):
		var enemy := enemy_variant as Node
		if enemy == null:
			continue
		if "is_dead" in enemy and bool(enemy.is_dead):
			continue
		var enemy_room := int(enemy.get_meta("room_id", -1))
		if enemy_room < 0 and navigation_service and navigation_service.has_method("get_enemy_room_id"):
			enemy_room = int(navigation_service.get_enemy_room_id(enemy))
		if enemy_room == room_id:
			return true
	return false
