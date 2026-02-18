## zone_director.gd
## Zone-level escalation state machine (CALM/ELEVATED/LOCKDOWN).
class_name ZoneDirector
extends Node


enum ZoneState {
	CALM = 0,
	ELEVATED = 1,
	LOCKDOWN = 2,
}

var _zone_states: Dictionary = {} # zone_id -> ZoneState
var _zone_rooms: Dictionary = {} # zone_id -> Array[int] room_ids
var _room_to_zone: Dictionary = {} # room_id -> zone_id
var _zone_graph: Dictionary = {} # zone_id -> Array[int] neighbor zone_ids
var _reinforcement_waves: Dictionary = {} # zone_id -> int count
var _reinforcement_enemies: Dictionary = {} # zone_id -> int count
var _pending_spreads: Array[Dictionary] = [] # {"zone_id", "target_state", "time_remaining"}
var _alert_system: EnemyAlertSystem = null


func initialize(zone_config: Array[Dictionary], zone_edges: Array[Array], alert_system: EnemyAlertSystem = null) -> void:
	_zone_states.clear()
	_zone_rooms.clear()
	_room_to_zone.clear()
	_zone_graph.clear()
	_reinforcement_waves.clear()
	_reinforcement_enemies.clear()
	_pending_spreads.clear()
	_alert_system = alert_system

	for zone_variant in zone_config:
		var zone_id := int(zone_variant.get("id", -1))
		if zone_id < 0:
			continue
		_ensure_zone_entry(zone_id)
		var rooms: Array[int] = []
		for room_variant in (zone_variant.get("rooms", []) as Array):
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


func get_zone_state(zone_id: int) -> int:
	if zone_id < 0:
		return -1
	return int(_zone_states.get(zone_id, -1))


func get_zone_for_room(room_id: int) -> int:
	if room_id < 0:
		return -1
	return int(_room_to_zone.get(room_id, -1))


func trigger_lockdown(zone_id: int) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	if get_zone_state(zone_id) == ZoneState.LOCKDOWN:
		return

	_set_zone_state(zone_id, ZoneState.LOCKDOWN)

	var spread_config := _get_spread_config()
	var distances := _collect_zone_distances(zone_id)
	for target_variant in distances.keys():
		var target_zone_id := int(target_variant)
		if target_zone_id == zone_id:
			continue
		if get_zone_state(target_zone_id) == ZoneState.LOCKDOWN:
			continue
		var hops := int(distances.get(target_zone_id, 0))
		var delay: float = float(spread_config.get("elevated_delay", 2.0)) if hops <= 1 else float(spread_config.get("far_delay", 5.0))
		_queue_spread(target_zone_id, ZoneState.ELEVATED, delay)


func trigger_elevated(zone_id: int) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	if get_zone_state(zone_id) != ZoneState.CALM:
		return
	_set_zone_state(zone_id, ZoneState.ELEVATED)


func update(delta: float) -> void:
	if _pending_spreads.is_empty():
		return
	var dt := maxf(delta, 0.0)
	var next_spreads: Array[Dictionary] = []
	for pending_variant in _pending_spreads:
		var pending := (pending_variant as Dictionary).duplicate(true)
		var time_remaining := float(pending.get("time_remaining", 0.0)) - dt
		pending["time_remaining"] = time_remaining
		if time_remaining > 0.0:
			next_spreads.append(pending)
			continue
		var zone_id := int(pending.get("zone_id", -1))
		var target_state := int(pending.get("target_state", ZoneState.ELEVATED))
		_apply_spread_target(zone_id, target_state)
	_pending_spreads = next_spreads


func can_spawn_reinforcement(zone_id: int) -> bool:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return false
	var caps := _get_reinforcement_caps()
	var waves := int(_reinforcement_waves.get(zone_id, 0))
	var enemies := int(_reinforcement_enemies.get(zone_id, 0))
	return waves < caps.max_waves and enemies < caps.max_enemies


func register_reinforcement_wave(zone_id: int, count: int) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	var clamped_count := maxi(count, 0)
	_reinforcement_waves[zone_id] = int(_reinforcement_waves.get(zone_id, 0)) + 1
	_reinforcement_enemies[zone_id] = int(_reinforcement_enemies.get(zone_id, 0)) + clamped_count


func _ensure_zone_entry(zone_id: int) -> void:
	if not _zone_states.has(zone_id):
		_zone_states[zone_id] = ZoneState.CALM
	if not _zone_rooms.has(zone_id):
		_zone_rooms[zone_id] = []
	if not _zone_graph.has(zone_id):
		_zone_graph[zone_id] = []
	if not _reinforcement_waves.has(zone_id):
		_reinforcement_waves[zone_id] = 0
	if not _reinforcement_enemies.has(zone_id):
		_reinforcement_enemies[zone_id] = 0


func _set_zone_state(zone_id: int, new_state: int) -> void:
	if zone_id < 0:
		return
	var old_state := get_zone_state(zone_id)
	if old_state == new_state:
		return
	_zone_states[zone_id] = new_state
	if EventBus:
		if EventBus.has_method("emit_zone_state_changed"):
			EventBus.emit_zone_state_changed(zone_id, old_state, new_state)
		elif EventBus.has_signal("zone_state_changed"):
			EventBus.zone_state_changed.emit(zone_id, old_state, new_state)


func _apply_spread_target(zone_id: int, target_state: int) -> void:
	if target_state == ZoneState.LOCKDOWN:
		trigger_lockdown(zone_id)
		return
	if target_state == ZoneState.ELEVATED:
		trigger_elevated(zone_id)


func _queue_spread(zone_id: int, target_state: int, delay_sec: float) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	var delay := maxf(delay_sec, 0.0)
	for i in range(_pending_spreads.size()):
		var pending := _pending_spreads[i] as Dictionary
		if int(pending.get("zone_id", -1)) != zone_id:
			continue
		if int(pending.get("target_state", -1)) != target_state:
			continue
		var existing_delay := float(pending.get("time_remaining", INF))
		if delay < existing_delay:
			pending["time_remaining"] = delay
			_pending_spreads[i] = pending
		return
	_pending_spreads.append({
		"zone_id": zone_id,
		"target_state": target_state,
		"time_remaining": delay,
	})


func _collect_zone_distances(source_zone_id: int) -> Dictionary:
	var distances: Dictionary = {source_zone_id: 0}
	var queue: Array[int] = [source_zone_id]
	var qi := 0
	while qi < queue.size():
		var zone_id := int(queue[qi])
		qi += 1
		var zone_distance := int(distances.get(zone_id, 0))
		for neighbor_variant in (_zone_graph.get(zone_id, []) as Array):
			var neighbor_id := int(neighbor_variant)
			if neighbor_id < 0:
				continue
			if distances.has(neighbor_id):
				continue
			distances[neighbor_id] = zone_distance + 1
			queue.append(neighbor_id)
	return distances


func _get_spread_config() -> Dictionary:
	var elevated_delay := 2.0
	var far_delay := 5.0
	if GameConfig and GameConfig.zone_system is Dictionary:
		var zone_system := GameConfig.zone_system as Dictionary
		elevated_delay = maxf(float(zone_system.get("lockdown_spread_delay_elevated_sec", elevated_delay)), 0.0)
		far_delay = maxf(float(zone_system.get("lockdown_spread_delay_far_sec", far_delay)), elevated_delay)
	return {
		"elevated_delay": elevated_delay,
		"far_delay": far_delay,
	}


func _get_reinforcement_caps() -> Dictionary:
	var max_waves := 1
	var max_enemies := 2
	if GameConfig and GameConfig.zone_system is Dictionary:
		var zone_system := GameConfig.zone_system as Dictionary
		max_waves = maxi(int(zone_system.get("max_reinforcement_waves_per_zone", max_waves)), 0)
		max_enemies = maxi(int(zone_system.get("max_reinforcement_enemies_per_zone", max_enemies)), 0)
	return {
		"max_waves": max_waves,
		"max_enemies": max_enemies,
	}
