## enemy_alert_system.gd
## Room-level alert propagation/decay state machine driven by gameplay events.
class_name EnemyAlertSystem
extends Node

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var room_nav_system: Node = null
var _room_states: Dictionary = {}      # room_id -> {"level": int, "ttl": float}
var _enemy_room_cache: Dictionary = {} # enemy_id -> room_id


func initialize(p_room_nav_system: Node) -> void:
	bind_room_nav(p_room_nav_system)
	_connect_event_bus_signals()
	reset_all()


func bind_room_nav(p_room_nav_system: Node) -> void:
	room_nav_system = p_room_nav_system


func reset_all() -> void:
	_room_states.clear()
	_enemy_room_cache.clear()


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	var room_ids: Array = _room_states.keys()
	for rid_variant in room_ids:
		var room_id := int(rid_variant)
		if not _room_states.has(room_id):
			continue
		var state := _room_states[room_id] as Dictionary
		var level := int(state.get("level", ENEMY_ALERT_LEVELS_SCRIPT.CALM))
		if level <= ENEMY_ALERT_LEVELS_SCRIPT.CALM:
			_room_states.erase(room_id)
			continue
		var ttl := maxf(0.0, float(state.get("ttl", 0.0)) - delta)
		if ttl > 0.0:
			state["ttl"] = ttl
			_room_states[room_id] = state
			continue
		_decay_room_level(room_id, level)


func _process(delta: float) -> void:
	update(delta)


func get_room_alert_level(room_id: int) -> int:
	if room_id < 0:
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	if not _room_states.has(room_id):
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var state := _room_states[room_id] as Dictionary
	return int(state.get("level", ENEMY_ALERT_LEVELS_SCRIPT.CALM))


func get_room_alert_ttl(room_id: int) -> float:
	if room_id < 0 or not _room_states.has(room_id):
		return 0.0
	var state := _room_states[room_id] as Dictionary
	return maxf(0.0, float(state.get("ttl", 0.0)))


func get_alert_level_for_enemy(enemy: Node) -> int:
	if not enemy:
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id < 0 and room_nav_system and room_nav_system.has_method("get_enemy_room_id"):
		room_id = int(room_nav_system.get_enemy_room_id(enemy))
	return get_room_alert_level(room_id)


func get_state_snapshot() -> Dictionary:
	return _room_states.duplicate(true)


func raise_combat_immediate(room_id: int, source_enemy_id: int = -1) -> void:
	if room_id < 0:
		return
	if source_enemy_id > 0:
		_enemy_room_cache[source_enemy_id] = room_id
	_raise_room_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	for neighbor_id in _neighbor_rooms(room_id):
		_raise_room_level(neighbor_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)


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
	_raise_room_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.ALERT)
	for neighbor_id in _neighbor_rooms(room_id):
		_raise_room_level(neighbor_id, ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)


func _on_enemy_player_spotted(enemy_id: int, position: Vector3) -> void:
	var room_id := _room_id_at_position(Vector2(position.x, position.y))
	if room_id < 0:
		room_id = _resolve_enemy_room(enemy_id)
	if room_id < 0:
		return
	raise_combat_immediate(room_id, enemy_id)


func _on_enemy_killed(enemy_id: int, _enemy_type: String) -> void:
	var room_id := _resolve_enemy_room(enemy_id)
	if room_id < 0:
		return
	_raise_room_level(room_id, ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)
	_enemy_room_cache.erase(enemy_id)


func _raise_room_level(room_id: int, level: int) -> void:
	if room_id < 0:
		return
	var target_level := clampi(level, ENEMY_ALERT_LEVELS_SCRIPT.CALM, ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	if target_level <= ENEMY_ALERT_LEVELS_SCRIPT.CALM:
		_room_states.erase(room_id)
		return

	var current_level := get_room_alert_level(room_id)
	if target_level < current_level:
		return

	var new_ttl := ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(target_level)
	if _room_states.has(room_id):
		var current := _room_states[room_id] as Dictionary
		if target_level == current_level:
			new_ttl = maxf(new_ttl, float(current.get("ttl", 0.0)))
	_room_states[room_id] = {
		"level": target_level,
		"ttl": new_ttl,
	}


func _decay_room_level(room_id: int, level: int) -> void:
	var new_level := level - 1
	if new_level <= ENEMY_ALERT_LEVELS_SCRIPT.CALM:
		_room_states.erase(room_id)
		return
	_room_states[room_id] = {
		"level": new_level,
		"ttl": ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(new_level),
	}


func _room_id_at_position(pos: Vector2) -> int:
	if room_nav_system and room_nav_system.has_method("room_id_at_point"):
		return int(room_nav_system.room_id_at_point(pos))
	return -1


func _neighbor_rooms(room_id: int) -> Array[int]:
	var out: Array[int] = []
	if room_id < 0 or not room_nav_system:
		return out
	var neighbors: Array = []
	if room_nav_system.has_method("get_neighbors"):
		neighbors = room_nav_system.get_neighbors(room_id) as Array
	elif room_nav_system.has_method("get_adjacent_room_ids"):
		neighbors = room_nav_system.get_adjacent_room_ids(room_id) as Array
	for rid_variant in neighbors:
		var rid := int(rid_variant)
		if rid >= 0 and rid != room_id:
			out.append(rid)
	return out


func _resolve_enemy_room(enemy_id: int) -> int:
	if _enemy_room_cache.has(enemy_id):
		return int(_enemy_room_cache[enemy_id])
	if room_nav_system and room_nav_system.has_method("get_enemy_room_id_by_id"):
		var room_id := int(room_nav_system.get_enemy_room_id_by_id(enemy_id))
		if room_id >= 0:
			_enemy_room_cache[enemy_id] = room_id
			return room_id
	return -1
